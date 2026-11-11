class_name Duel
extends Node3D

enum EState {INTRO, IDLE, WINDUP, RECOVER, OPEN, FINISHER, DEAD}
enum PState {READY, DODGE, SWING, HIT, DEAD}

const DODGE_TIME := 0.46
const DODGE_IFRAME := 0.38
const PERFECT_DODGE := 0.18
const PERFECT_PARRY := 0.11
const WHIFF_LOCK := 0.34
const BUFFER_MS := 220
const CAM_POS := Vector3(0.55, 1.9, 4.4)
const CAM_LOOK := Vector3(0.2, 1.8, -0.8)
const TITLE_CAM := Vector3(4.6, 1.5, 1.8)
const TITLE_LOOK := Vector3(-0.3, 1.5, 0.2)

const COMBOS := [
	{"name": "TEMPEST", "seq": ["L", "R", "U", "D"], "mult": 3.0},
	{"name": "TEMPEST", "seq": ["R", "L", "U", "D"], "mult": 3.0},
	{"name": "CLEAVE", "seq": ["L", "L", "R", "R"], "mult": 2.2},
	{"name": "CLEAVE", "seq": ["R", "R", "L", "L"], "mult": 2.2},
	{"name": "FLURRY", "seq": ["L", "R", "L"], "mult": 1.35},
	{"name": "FLURRY", "seq": ["R", "L", "R"], "mult": 1.35},
]

var host: Node3D
var player: FighterVisual
var enemy: FighterVisual
var foes: Array = []
var others: Array = []
var slain: Array = []

var pvp := {}
var pvp_turn := ""
var pvp_left := 0
var _pvp_cool := 0.0
var _pvp_idle := 0.0
var _pvp_quiet := 0.0
var _pvp_ping := 0.0
var _bot_decided := false
var _pvp_turn_due := false
var _pvp_wait := 0.0
var _enc := {}

var def: EnemyDef
var hud: Hud
var sfx: Sfx
var cam: Camera3D
var sparks: CPUParticles3D

var player_max_hp := 100.0
var shield_max := 60.0
var slash_damage := 7.0
var parry_window := 0.3
var surge_rate := 1.0
var dodge_max := 3
var leech := 0.0
var dodge_regen := 0.6
var slash_lock := 0.24
var break_mult := 1.0
var perfect_block := 0.2
var family := "longsword"
var element := ""
var burn := 0.0
var _burn_tick := 0.0
var chill := 0.0

var ranged_id := ""
var shots := 0
var spell_id := ""
var mana := 0.0
var warded := false
var can_spare := false
var ranged_mult := 1.0
var spell_mult := 1.0
var mana_rate := 4.5
var _start_note := ""
var spared := false
var was_in_tower := false

var started := false
var paused := false
var e_state := EState.INTRO
var e_timer := 1.4
var e_hp := 0.0
var e_break := 0.0
var e_speed := 1.0
var enraged := false
var open_reason := ""
var combo: Array = []
var combo_i := 0
var cur_attack: AttackDef
var windup_total := 1.0
var _feinted := false
var _feint_hold := 0.0

var p_state := PState.READY
var p_timer := 0.0
var p_hp := 0.0
var shield := 0.0
var blocking := false
var _block_wanted := false
var _block_time := -10.0
var dodge_dir := 0
var dodge_elapsed := 0.0
var dodge_charges := 3.0
var player_home := Vector3.ZERO
var super_meter := 0.0
var slash_seq: Array = []

var hit_combo := 0
var stats := {"time": 0.0, "parries": 0, "perfect": 0, "dodges": 0, "best_combo": 0, "hits_taken": 0,
	"sword_dmg": 0.0, "blocks": 0, "shots": 0, "casts": 0, "dmg_taken": 0.0}
var result := ""
var reward := {}

var tutorial := false
var tutorial_hint := ""
var _tutorial_queue: Array = []
var _tutorial_slowed := false

var cinematic := 1.0
var _shake := 0.0
var _cam_offset_x := 0.0
var _look := TITLE_LOOK
var _time_token := 0
var _base_time := 1.0
var _bot := ""
var _move_tw: Tween
var _cam_tw: Tween
var _shot_path := ""
var _shot_when := "windup"
var _buf := {"kind": "", "v": Vector2.ZERO, "dir": 0, "ms": 0}
var _t := 0.0
var _met_before := false


func _ready() -> void:
	randomize()
	Run.ensure_loaded()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoplay="):
			_bot = a.trim_prefix("--autoplay=")
			_base_time = 4.0
			if _bot.begins_with("pvp"):
				_bot = "pvp"
			if _bot != "tour" and host == null:
				Run.no_save = true
				Run.data = Run.defaults()
				Run.data.tutorial_done = true
		elif a.begins_with("--kind="):
			Run.encounter = {"id": "test", "kind": a.trim_prefix("--kind=")}
			Run.data.in_tower = true
		elif a.begins_with("--wild="):
			Run.encounter = {"id": "test", "wild": a.trim_prefix("--wild=")}
		elif a.begins_with("--skills="):
			for sk in Craft.SKILLS:
				Run.data.skills[sk] = Craft.xp_for(int(a.trim_prefix("--skills=")))
		elif a.begins_with("--floor="):
			Run.data.floor = int(a.trim_prefix("--floor="))
		elif a.begins_with("--equip="):
			for id in a.trim_prefix("--equip=").split(","):
				Run.data.inventory.append(id)
				Run.equip(id)
		elif a.begins_with("--loop="):
			Run.data.loop = int(a.trim_prefix("--loop="))
		elif a.begins_with("--shot="):
			_shot_path = a.trim_prefix("--shot=")
			Run.no_save = true
		elif a.begins_with("--shot-when="):
			_shot_when = a.trim_prefix("--shot-when=")
			if _shot_when != "title":
				Run.title_seen = true
				Run.data.tutorial_done = _shot_when != "tutorial"
	Engine.time_scale = _base_time
	AudioServer.set_bus_mute(0, not Run.data.sound)
	Run.apply_web_settings(get_viewport())

	if host == null:
		player = $Player
		enemy = $Enemy
		if Run.encounter.has("wild"):
			def = EnemyDef.make_wild(Run.encounter.wild)
		else:
			def = EnemyDef.make_encounter(Run.encounter.get("kind", "guardian"), int(Run.data.floor), int(Run.data.loop))
		foes = [{"node": enemy, "def": def, "enc": Run.encounter}]
		player.configure(Run.look())
		enemy.configure(def.look)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--pack="):
				for i in int(a.trim_prefix("--pack=")):
					var extra := preload("res://scenes/placeholder_fighter.tscn").instantiate() as FighterVisual
					add_child(extra)
					var d2 := EnemyDef.make_wild(Run.encounter.get("wild", "thrall"))
					extra.configure(d2.look)
					foes.append({"node": extra, "def": d2, "enc": Run.encounter})
	else:
		enemy = foes[0].node
		def = foes[0].def
		if not pvp.is_empty():
			def = EnemyDef.new()
			def.display_name = pvp.name
			def.title = ""
			def.kind = "player"
			def.max_hp = float(pvp.max_hp)
			foes[0].def = def
			Online.message.connect(_pvp_message)
			if _bot != "":
				_base_time = 1.0
				Engine.time_scale = 1.0
		_place_in_world()
	_enc = foes[0].enc
	Run.encounter = _enc
	for i in range(1, foes.size()):
		var o: Dictionary = foes[i]
		o.merge({"hp": o.def.max_hp, "brk": 0.0, "enr": false, "spd": o.def.speed, "side": -1.0 if i % 2 == 1 else 1.0,
			"timer": 4.0 + i * 2.5, "tell": 0.0})
		others.append(o)
		_seat(o)
	e_hp = def.max_hp
	e_speed = def.speed
	var ps := Run.stats()
	player_max_hp = ps.max_hp
	slash_damage = ps.damage
	shield_max = ps.shield_max
	surge_rate = ps.surge_rate
	parry_window = ps.parry_window
	dodge_max = ps.dodge_max
	dodge_regen = ps.dodge_regen
	leech = ps.leech
	slash_lock = ps.slash_lock
	break_mult = ps.break_mult
	perfect_block = ps.perfect_block
	family = ps.family
	element = ps.element
	ranged_mult = ps.ranged_mult
	spell_mult = ps.spell_mult
	mana_rate = ps.mana_rate
	ranged_id = Run.data.equipped.get("ranged", "")
	shots = int(Items.info(ranged_id).get("shots", 0)) + (1 if ranged_id != "" and Run.perk("a1") else 0)
	if ranged_id == "hunters_bow":
		shots = mini(shots, Run.mat("arrow"))
	if not pvp.is_empty():
		shots = 0
		ranged_id = ""

	if (_bot == "" or _bot == "tour") and pvp.is_empty():
		var fed := Run.eat_meal()
		if fed > 0:
			player_max_hp += fed
			_start_note = "WELL FED +%d" % fed
		if Run.mat("tonic") > 0:
			Run.add_mat("tonic", -1)
			super_meter = 100.0
	spell_id = Run.data.equipped.get("spell", "") if pvp.is_empty() else ""
	can_spare = def.display_name == "The Hollow Regent" and Run.data.relics.size() >= Run.FLOORS
	p_hp = player_max_hp
	shield = shield_max
	dodge_charges = dodge_max
	player_home = player.position
	tutorial = not Run.data.tutorial_done and others.is_empty() and pvp.is_empty()
	if tutorial:
		_tutorial_queue = [AttackDef.Dir.LEFT, AttackDef.Dir.RIGHT, AttackDef.Dir.OVER, AttackDef.Dir.THRUST]

	cam = Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	if host != null and host.get("cam") != null:
		cam.global_transform = (host.cam as Camera3D).global_transform
		_look = to_local(player.global_position + Vector3(0, 1.5, 0))
	else:
		cam.position = TITLE_CAM
		cam.look_at(to_global(_look))
	cam.make_current()

	sfx = Sfx.new()
	sfx.ambience = host == null
	add_child(sfx)
	sparks = _make_sparks()
	add_child(sparks)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.duel = self
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	enemy.play(&"idle")
	player.play(&"idle")
	begin()


func _ground(world_pos: Vector3) -> float:
	if host != null and host.has_method("ground_y"):
		return host.ground_y(world_pos)
	return global_position.y


func _place_in_world() -> void:
	var hp := player.global_position
	var ep := enemy.global_position
	var dir := ep - hp
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var mid := hp.lerp(ep, 0.5)
	mid.y = _ground(mid)
	global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), mid)
	for f in [player, enemy]:
		_adopt(f)
	_stand(player, Vector3(-1.2, 0, 2.0), 0.0)
	_stand(enemy, Vector3(0, 0, -0.75), PI)


func _adopt(f: Node3D) -> void:
	if f.get_parent() != self:
		f.set_meta("duel_parent", f.get_parent())
		f.reparent(self)


func _stand(f: Node3D, local: Vector3, yaw: float, glide := 0.0) -> void:
	var world := to_global(local)
	local.y = _ground(world) - global_position.y
	if glide > 0.0:
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(f, "position", local, glide)
		tw.tween_property(f, "rotation:y", yaw, glide)
	else:
		f.position = local
		f.rotation = Vector3(0, yaw, 0)


func _seat(o: Dictionary, glide := 0.0) -> void:
	_adopt(o.node)
	_stand(o.node, Vector3(3.3 * float(o.side), 0, -0.1), PI - 0.75 * float(o.side), glide)
	(o.node as FighterVisual).play(&"idle")


func _release() -> void:
	var all: Array = [player, enemy]
	for o in others:
		all.append(o.node)
	for r in slain:
		all.append(r.node)
	for f in all:
		if is_instance_valid(f) and f.has_meta("duel_parent") and f.get_parent() == self:
			var parent: Node = f.get_meta("duel_parent")
			if is_instance_valid(parent):
				f.reparent(parent)
			f.remove_meta("duel_parent")


func _pvp_my_turn() -> void:
	pvp_turn = "attack"
	pvp_left = 3
	_pvp_cool = 0.7
	_pvp_idle = 0.0
	hud.banner("YOUR ATTACK", Color(1.0, 0.8, 0.4), 0.9)


func _pvp_their_turn(tell_them := true) -> void:
	pvp_turn = "defend"
	pvp_left = 0
	_pvp_wait = 0.0
	if tell_them:
		Online.send_to(pvp.id, {"k": "turn"})
	hud.banner("DEFEND", Color(0.6, 0.8, 1.0), 0.9)


func _pvp_tick(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	if e_state == EState.INTRO:
		e_timer -= delta
		if e_timer <= 0.0:
			e_state = EState.IDLE
			enemy.play(&"idle")
			if pvp.first:
				_pvp_my_turn()
			else:
				_pvp_their_turn(false)
		return
	_pvp_cool -= delta
	_pvp_quiet += real
	_pvp_ping += real
	if _pvp_ping > 3.0:
		_pvp_ping = 0.0
		Online.send_to(pvp.id, {"k": "ping", "hp": p_hp})
	if _pvp_quiet > 14.0 and result == "":
		hud.banner("%s has left" % pvp.name, Color(1, 1, 1), 1.2)
		reward.left = true
		_end("win")
		return
	if pvp_turn == "defend":
		_pvp_wait += real

		if e_state == EState.IDLE and p_state != PState.DEAD and (_pvp_turn_due or _pvp_wait > 9.0):
			_pvp_turn_due = false
			_pvp_my_turn()
	if pvp_turn == "attack":
		_pvp_idle += real
		if (pvp_left <= 0 and _pvp_cool <= -0.9) or _pvp_idle > 6.0:
			_pvp_their_turn()
	if _bot == "pvp":
		_pvp_bot()


func _pvp_attack(letter: String) -> void:
	if pvp_turn != "attack" or pvp_left <= 0 or _pvp_cool > 0.0 or p_state != PState.READY:
		return
	pvp_left -= 1
	_pvp_cool = 1.25
	_pvp_idle = 0.0

	var dir: int = {"L": AttackDef.Dir.LEFT, "R": AttackDef.Dir.RIGHT, "D": AttackDef.Dir.OVER, "U": AttackDef.Dir.THRUST} [letter]
	Online.send_to(pvp.id, {"k": "atk", "dir": dir, "dmg": slash_damage * (2.6 if dir == AttackDef.Dir.OVER else 2.0)})
	p_state = PState.SWING
	p_timer = 0.5
	player.play(&"slash", {"L": -1, "R": 1, "U": 2, "D": 3} [letter] as int, 0.35)
	sfx.play("whoosh", -6.0)


func _pvp_report(outcome: String, riposte := 0.0) -> void:
	if pvp.is_empty():
		return
	Online.send_to(pvp.id, {"k": "res", "o": outcome, "hp": maxf(p_hp, 0.0), "rip": riposte})


func _pvp_message(from: String, m: Dictionary) -> void:
	if from != String(pvp.id) or result != "":
		return
	_pvp_quiet = 0.0
	if m.has("hp"):
		e_hp = clampf(float(m.hp), 0.0, def.max_hp)
	match String(m.get("k", "")):
		"atk":
			if e_state == EState.INTRO:
				e_state = EState.IDLE
			pvp_turn = "defend"
			_pvp_wait = 0.0
			_pvp_turn_due = false
			cur_attack = AttackDef.make(int(m.dir), 0.9, float(m.dmg))
			combo = [cur_attack]
			combo_i = 0
			_begin_attack()
		"res":
			var at := enemy.get_clash_point() + Vector3(randf_range(-0.3, 0.3), 0.4, 0)
			match String(m.o):
				"hit":
					enemy.play(&"hit", [-1, 1].pick_random(), 0.12)
					enemy.flash(Color(1.0, 0.9, 0.7))
					sfx.play("hit")
					_burst(enemy.get_clash_point(), 10)
					hud.float_text("HIT", at, Color(1.0, 0.9, 0.5), true)
					_hitstop(0.05)
					stats.sword_dmg += 12.0
				"dodged": hud.float_text("DODGED", at, Color(0.7, 0.85, 1.0))
				"blocked":
					sfx.play("block")
					hud.float_text("BLOCKED", at, Color(0.7, 0.8, 1.0))
				"parried":
					sfx.play("clang")
					_burst(player.get_clash_point().lerp(enemy.get_clash_point(), 0.5), 24)
					hud.banner("PARRIED!", Color(1.0, 0.5, 0.4), 0.7)
					pvp_turn = "defend"
					pvp_left = 0
					_hurt(float(m.get("rip", 10.0)), AttackDef.Dir.LEFT)
		"turn":
			_pvp_turn_due = true
		"dead":
			var won := int(m.get("gold", 0))
			Run.data.gold += won
			Run.data.pvp_w += 1
			reward.gold = won
			e_hp = 0.0
			e_state = EState.DEAD
			enemy.play(&"death")
			player.play(&"victory")
			sfx.play("finish", 2.0, 0.0)
			_shake = 1.2
			_end("win")


func _pvp_bot() -> void:
	if pvp_turn == "attack" and _pvp_cool <= 0.0 and pvp_left > 0 and p_state == PState.READY and e_state != EState.WINDUP:
		_pvp_attack(["L", "R", "D", "U"].pick_random())
	elif e_state == EState.WINDUP and e_timer <= parry_window * 0.6 and p_state == PState.READY and not _bot_decided:
		_bot_decided = true
		if randf() < 0.45 and cur_attack.dir != AttackDef.Dir.THRUST:
			input_swipe([Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1)][cur_attack.dir])
	if e_state != EState.WINDUP:
		_bot_decided = false


func _tick_others(delta: float) -> void:
	for o in others:
		var node: FighterVisual = o.node
		if float(o.tell) > 0.0:
			o.tell = float(o.tell) - delta
			if float(o.tell) <= 0.0:
				_side_strike(o)
			continue
		o.timer = float(o.timer) - delta
		if float(o.timer) > 0.0:
			continue
		if e_state == EState.WINDUP or e_state in [EState.INTRO, EState.FINISHER, EState.DEAD]:
			o.timer = 0.6
			continue
		o.tell = 1.25
		node.play(&"windup", AttackDef.Dir.THRUST, 1.25)
		node.set_tell(Color(1.0, 0.15, 0.1), 0.6)
		sfx.play("tell", -8.0, 0.02)


func _side_strike(o: Dictionary) -> void:
	var node: FighterVisual = o.node
	node.play(&"strike", AttackDef.Dir.THRUST, 0.1)
	node.set_tell(Color.BLACK, 0.2)
	o.timer = randf_range(3.5, 5.0) if (o.def as EnemyDef).ranged else randf_range(6.0, 9.0)
	get_tree().create_timer(0.45).timeout.connect(func():
		if is_instance_valid(node) and others.has(o):
			node.play(&"idle"))
	sfx.play("whoosh", -6.0)
	var dmg: float = (o.def as EnemyDef).side_damage
	if p_state == PState.DODGE and dodge_elapsed <= DODGE_IFRAME:
		stats.dodges += 1
		return
	if blocking and p_state == PState.READY:
		stats.blocks += 1
		sfx.play("block")
		shield -= dmg
		if shield <= 0.0:
			shield = 0.0
			blocking = false
			_hurt(dmg * 0.6, AttackDef.Dir.THRUST)
		return
	_hurt(dmg, AttackDef.Dir.RIGHT if float(o.side) > 0.0 else AttackDef.Dir.LEFT)


func switch_target(i: int) -> void:
	if i < 0 or i >= others.size() or result != "" or p_state == PState.DEAD:
		return
	if e_state in [EState.FINISHER, EState.DEAD, EState.INTRO]:
		return
	var next: Dictionary = others[i]
	if float(next.tell) > 0.0:
		(next.node as FighterVisual).set_tell(Color.BLACK, 0.1)
	var prev := {"node": enemy, "def": def, "enc": _enc, "hp": e_hp, "brk": e_break, "enr": enraged, "spd": e_speed,
		"side": next.side, "timer": 5.0, "tell": 0.0}
	others[i] = prev
	enemy.set_tell(Color.BLACK, 0.1)
	_seat(prev, 0.45)
	_face(next, 0.45)
	hud.banner(def.display_name, Color(1.0, 0.8, 0.5), 0.9)


func _face(rec: Dictionary, glide: float) -> void:
	enemy = rec.node
	def = rec.def
	_enc = rec.enc
	Run.encounter = _enc
	e_hp = rec.get("hp", def.max_hp)
	e_break = rec.get("brk", 0.0)
	enraged = rec.get("enr", false)
	e_speed = rec.get("spd", def.speed)
	burn = 0.0
	chill = 0.0
	hit_combo = 0
	_stand(enemy, Vector3(0, 0, -0.75), PI, glide)
	enemy.play(&"idle")
	e_state = EState.IDLE
	e_timer = 1.0
	open_reason = ""
	can_spare = false


func begin() -> void:
	if started:
		return
	started = true
	_met_before = Run.data.met.has(def.display_name)
	if not _met_before and def.kind == "guardian":
		Run.data.met.append(def.display_name)
	hud.caption(Story.bark(def.display_name, "intro", _met_before))
	if _start_note != "":
		hud.banner(_start_note, Color(0.6, 1.0, 0.6), 1.6)
	e_state = EState.INTRO
	e_timer = 2.0
	enemy.play(&"taunt")
	sfx.play("break", -8.0, 0.0)
	hud.banner(def.display_name if pvp.is_empty() else "DUEL: " + def.display_name, Color(1.0, 0.8, 0.5), 2.0)
	_cam_to(CAM_POS, CAM_LOOK, 1.6)
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(self, "cinematic", 0.0, 0.5)


func _cam_to(pos: Vector3, look: Vector3, t: float) -> void:
	if _cam_tw:
		_cam_tw.kill()
	_cam_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_cam_tw.tween_property(cam, "position", pos, t)
	_cam_tw.tween_property(self, "_look", look, t)


func _make_sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 28
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.5
	p.gravity = Vector3(0, -9, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1.0, 0.85, 0.5)
	q.material = m
	p.mesh = q
	return p


func _process(delta: float) -> void:
	_t += delta
	_update_camera(delta)
	_take_shot_if_due()
	if not started or result != "":
		return
	stats.time += delta
	_tick_player(delta)
	_tick_enemy(delta)
	_tick_others(delta)
	if _bot != "":
		_tick_bot()


func _update_camera(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	_shake = move_toward(_shake, 0.0, real * 2.2)
	var sway := Vector3.ZERO
	if not started:
		sway = Vector3(sin(_t * 0.25) * 0.5, sin(_t * 0.4) * 0.08, 0)
	cam.look_at(to_global(_look + sway))
	cam.h_offset = _cam_offset_x + randf_range(-1, 1) * _shake * 0.12
	cam.v_offset = randf_range(-1, 1) * _shake * 0.12
	cam.fov = move_toward(cam.fov, 55.0, real * 30.0)


func _take_shot_if_due() -> void:
	if _shot_path == "":
		return
	var due := false
	match _shot_when:
		"title": due = _t > 1.0
		"open": due = e_state == EState.OPEN and hit_combo >= 2
		"result": due = (result == "win" or result == "lose") and hud._result_age > 1.6
		_: due = e_state == EState.WINDUP and e_timer <= 0.6
	if _shot_when == "open" and e_state == EState.WINDUP and e_timer < 0.15:
		input_swipe([Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2.ZERO][cur_attack.dir])
	if _shot_when == "open" and e_state == EState.OPEN:
		input_swipe(Vector2([-1, 1][hit_combo % 2], 0))
	if _shot_when == "result" and result == "":
		_damage_enemy(9999.0)
		if e_state == EState.FINISHER:
			_finish()
	if due:
		var path := _shot_path
		_shot_path = ""
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()


func _tick_player(delta: float) -> void:
	if spell_id != "":
		mana = minf(mana + delta * mana_rate, 100.0)
	if p_state != PState.DODGE:
		dodge_charges = minf(dodge_charges + delta * dodge_regen, dodge_max)
	if not blocking:
		shield = minf(shield + delta * 2.0, shield_max)
	match p_state:
		PState.DODGE:
			dodge_elapsed += delta
			if dodge_elapsed >= DODGE_TIME:
				_player_ready()
		PState.SWING, PState.HIT:
			p_timer -= delta
			if p_timer <= 0.0:
				_player_ready()


func _player_ready() -> void:
	p_state = PState.READY
	blocking = _block_wanted and shield > 0.0
	player.play(&"block" if blocking else &"idle")

	if _buf.kind != "" and Time.get_ticks_msec() - int(_buf.ms) <= BUFFER_MS:
		var kind: String = _buf.kind
		_buf.kind = ""
		if kind == "swipe":
			input_swipe(_buf.v)
		elif kind == "dodge":
			input_dodge(_buf.dir)
	_buf.kind = ""


func _tick_enemy(delta: float) -> void:
	if not pvp.is_empty():
		var was_intro := e_state == EState.INTRO
		_pvp_tick(delta)
		if was_intro or e_state == EState.IDLE:
			return
	chill = maxf(chill - delta, 0.0)
	if burn > 0.0 and e_state not in [EState.FINISHER, EState.DEAD, EState.INTRO]:
		burn -= delta
		_burn_tick -= delta
		if _burn_tick <= 0.0:
			_burn_tick = 0.5
			var bd := slash_damage * 0.3 * _element_mult()
			hud.float_text(str(int(ceil(bd))), enemy.get_clash_point() + Vector3(randf_range(-0.3, 0.3), 0.6, 0), Items.ELEMENT_COLORS.ember)
			_damage_enemy(bd)
			if e_state == EState.FINISHER:
				return
	match e_state:
		EState.INTRO:
			e_timer -= delta
			if e_timer <= 0.0:
				_to_idle(0.6)
		EState.IDLE:
			e_timer -= delta
			if e_timer <= 0.0:
				_pick_combo()
				_begin_attack()
		EState.WINDUP:
			if _feint_hold > 0.0:
				_feint_hold -= delta
				return
			e_timer -= delta
			if cur_attack.feint and not _feinted and e_timer <= windup_total * 0.45:
				_feinted = true
				_feint_hold = 0.42 / e_speed
				enemy.play(&"feint", 0, _feint_hold)
				return
			if tutorial and combo.size() == 1 and not _tutorial_slowed and e_timer <= parry_window * 0.85:
				_tutorial_slowed = true
				_slow(0.07, 4.0)
			if e_timer <= 0.0:
				_resolve_strike()
		EState.RECOVER:
			e_timer -= delta
			if e_timer <= 0.0 and not pvp.is_empty():
				e_state = EState.IDLE
				enemy.play(&"idle")
			elif e_timer <= 0.0:
				combo_i += 1
				if combo_i < combo.size():
					_begin_attack()
				else:
					_open(def.winded_time / e_speed, "winded")
		EState.OPEN:
			e_timer -= delta
			if e_timer <= 0.0:
				hit_combo = 0
				_to_idle(def.idle_gap / e_speed)
		EState.FINISHER:
			e_timer -= delta / maxf(Engine.time_scale, 0.05)
			if e_timer <= 0.0:
				_finish()


func _pick_combo() -> void:
	combo_i = 0
	if not _tutorial_queue.is_empty():
		var d: int = _tutorial_queue.pop_front()
		combo = [AttackDef.make(d, 1.5, 10.0)]
		tutorial_hint = "dodge" if d == AttackDef.Dir.THRUST else "parry"
		return
	if tutorial:
		tutorial = false
		tutorial_hint = ""
		Run.data.tutorial_done = true
		Run.save()
	var pool: Array = def.combos.duplicate()
	if enraged:
		pool.append_array(def.enraged_combos)
	combo = pool.pick_random()


func _to_idle(gap: float) -> void:
	e_state = EState.IDLE
	e_timer = gap
	open_reason = ""
	if tutorial_hint == "strike":
		tutorial_hint = ""
	enemy.play(&"idle")


func _begin_attack() -> void:
	cur_attack = combo[combo_i]
	e_state = EState.WINDUP
	e_timer = cur_attack.windup / (e_speed * (0.8 if chill > 0.0 else 1.0))
	windup_total = e_timer
	_feinted = false
	_feint_hold = 0.0
	_tutorial_slowed = false
	enemy.play(&"windup", cur_attack.dir, e_timer)
	enemy.set_tell(tell_color(), e_timer * 0.6)
	sfx.play("tell", -14.0, 0.02)


func tell_color() -> Color:
	if cur_attack.dir == AttackDef.Dir.THRUST:
		return Color(1.0, 0.15, 0.1)
	if cur_attack.heavy:
		return Color(0.75, 0.3, 1.0)
	return Color(1.0, 0.6, 0.15)


func _open(duration: float, reason: String) -> void:
	e_state = EState.OPEN
	e_timer = duration
	open_reason = reason
	slash_seq.clear()
	enemy.set_tell(Color.BLACK, 0.1)
	enemy.play(&"broken" if reason == "broken" else &"stagger")
	if tutorial:
		tutorial_hint = "strike"
		e_timer = maxf(duration, 2.6)


func _dodge_avoids(dir: int) -> bool:
	if p_state != PState.DODGE or dodge_elapsed > DODGE_IFRAME:
		return false
	match dir:
		AttackDef.Dir.LEFT: return dodge_dir > 0
		AttackDef.Dir.RIGHT: return dodge_dir < 0
	return true


func _resolve_strike() -> void:
	var a := cur_attack
	enemy.play(&"strike", a.dir, 0.1)
	e_state = EState.RECOVER
	e_timer = 0.35 / e_speed
	if _tutorial_slowed:
		_restore_time()
	sfx.play("whoosh", -6.0)
	if _dodge_avoids(a.dir):
		_pvp_report("dodged")
		stats.dodges += 1
		if dodge_elapsed <= PERFECT_DODGE:
			_add_surge(10.0)
			dodge_charges = minf(dodge_charges + 1.0, dodge_max)
			hud.banner("PERFECT DODGE", Color(0.6, 0.9, 1.0), 0.6)
			_slow(0.35, 0.18)
			if Run.set_bonus("duelist"):
				var rd := slash_damage * 2.0
				hud.float_text("RIPOSTE %d" % int(rd), enemy.get_clash_point(), Color(0.4, 0.9, 0.8), true)
				e_hp = maxf(e_hp - rd, 1.0)
		return
	if blocking and p_state == PState.READY:
		stats.blocks += 1
		_pvp_report.call_deferred("blocked")
		_shake = maxf(_shake, 0.5)
		sfx.play("block")
		_burst(player.get_clash_point() + Vector3(0, 0, -0.5), 10)
		_buzz(25)
		if a.heavy:
			shield = maxf(shield - a.damage, 0.0)
			hud.banner("GUARD CRUSHED", Color(0.8, 0.45, 1.0), 0.8)
			_hurt(a.damage, a.dir)
		elif stats.time - _block_time <= perfect_block:
			_add_surge(8.0)
			hud.banner("PERFECT BLOCK", Color(0.6, 0.8, 1.0), 0.6)
		else:
			shield -= a.damage
			if shield <= 0.0:
				shield = 0.0
				blocking = false
				hud.banner("GUARD BROKEN", Color(1.0, 0.5, 0.3), 0.8)
				if Run.set_bonus("warden"):
					shield = shield_max * 0.5
				_hurt(a.damage * 0.6, a.dir)
		return
	_hurt(a.damage, a.dir)
	_pvp_report("hit")


func _hurt(dmg: float, dir: int) -> void:
	if warded:
		warded = false
		hud.banner("WARDED", Color(0.6, 0.75, 1.0), 0.6)
		sfx.play("clang", -4.0)
		_burst(player.get_clash_point() + Vector3(0, 0, -0.5), 20)
		return
	p_hp -= dmg
	hit_combo = 0
	stats.hits_taken += 1
	stats.dmg_taken += dmg
	_add_surge(6.0)
	_shake = 1.0
	sfx.play("hurt")
	hud.hurt_flash()
	hud.enemy_streak(dir)
	player.flash(Color(1, 0.2, 0.15))
	player.play(&"hit", [-1, 1].pick_random(), 0.15)
	_hitstop(0.07)
	_buzz(60)
	if p_hp <= 0.0 and tutorial:
		p_hp = 1.0
	if p_hp <= 0.0:
		p_hp = 0.0
		p_state = PState.DEAD
		blocking = false
		player.play(&"death")
		enemy.play(&"victory")
		_slow(0.3, 1.0)
		if not pvp.is_empty():
			var stake := mini(int(int(Run.data.gold) * 0.1), 200) if pvp.zone else 0
			Run.data.gold -= stake
			Run.data.pvp_l += 1
			reward.lost_gold = stake
			Online.send_to(pvp.id, {"k": "dead", "gold": stake})
		_end("lose")
	else:
		p_state = PState.HIT
		p_timer = 0.36


func _buffer(kind: String, v := Vector2.ZERO, dir := 0) -> void:
	_buf = {"kind": kind, "v": v, "dir": dir, "ms": Time.get_ticks_msec()}


func _add_surge(amount: float) -> void:
	super_meter = minf(super_meter + amount * surge_rate, 100.0)


func _element_mult() -> float:
	if element == "":
		return 1.0
	if element == def.weak:
		return 1.3
	if element == def.resist:
		return 0.75
	return 1.0


static func swipe_letter(v: Vector2) -> String:
	if absf(v.x) >= absf(v.y):
		return "L" if v.x < 0.0 else "R"
	return "U" if v.y < 0.0 else "D"


func input_swipe(v: Vector2) -> void:
	if result != "" or not started or paused or blocking or p_state == PState.DEAD:
		return
	if not pvp.is_empty() and e_state != EState.WINDUP:
		_pvp_attack(swipe_letter(v))
		return
	if p_state != PState.READY:
		_buffer("swipe", v)
		return
	var letter := swipe_letter(v)
	var anim_dir := {"L": -1, "R": 1, "U": 2, "D": 3} [letter] as int
	match e_state:
		EState.FINISHER:
			_finish()
		EState.OPEN:
			_slash_hit(v, letter, anim_dir)
		EState.WINDUP:
			if cur_attack.dir != AttackDef.Dir.THRUST and e_timer <= parry_window and _parry_matches(letter):
				_parry(-1 if letter == "L" else 1)
			else:
				_whiff(anim_dir)
		EState.IDLE, EState.RECOVER:
			p_state = PState.SWING
			p_timer = 0.28
			player.play(&"slash", anim_dir, 0.12)
			enemy.play(&"guard")
			sfx.play("block", -6.0)
			_burst(enemy.get_clash_point(), 6)
			hud.float_text("GUARDED", enemy.get_clash_point(), Color(0.75, 0.75, 0.8))
			get_tree().create_timer(0.25).timeout.connect(func():
				if e_state == EState.IDLE:
					enemy.play(&"idle"))


func _parry_matches(letter: String) -> bool:
	match cur_attack.dir:
		AttackDef.Dir.LEFT: return letter == "L"
		AttackDef.Dir.RIGHT: return letter == "R"
		AttackDef.Dir.OVER: return letter == "U"
	return false


func _whiff(anim_dir: int) -> void:
	p_state = PState.SWING
	p_timer = WHIFF_LOCK
	player.play(&"slash", anim_dir, 0.14)
	sfx.play("whoosh", -8.0)
	if _tutorial_slowed:
		_restore_time()


func _parry(side: int) -> void:
	var perfect := e_timer <= PERFECT_PARRY and not _tutorial_slowed
	stats.parries += 1
	p_state = PState.SWING
	p_timer = 0.1
	player.play(&"parry", side)
	sfx.play("clang")
	_shake = maxf(_shake, 0.7)
	cam.fov = 49.0
	var mid := player.get_clash_point().lerp(enemy.get_clash_point(), 0.6)
	_burst(mid, 28)
	_slow(0.25, 0.22)
	_buzz(40)
	if not pvp.is_empty():
		hud.banner("PARRY", Color(1.0, 0.95, 0.75), 0.5)
		e_state = EState.IDLE
		enemy.set_tell(Color.BLACK, 0.1)
		enemy.play(&"stagger")
		player.play(&"slash", -side, 0.12)
		_pvp_report("parried", slash_damage * 2.0)
		_pvp_my_turn()
		return
	_add_surge(15.0)
	mana = minf(mana + 10.0, 100.0)
	if leech > 0.0:
		p_hp = minf(p_hp + leech, player_max_hp)
	e_break += def.break_per_parry * break_mult * (1.6 if perfect else 1.0)
	if def.title == "caster" and cur_attack.heavy:
		var back := cur_attack.damage * 1.5
		hud.float_text("REFLECTED %d" % int(back), enemy.get_clash_point() + Vector3(0, 0.6, 0), Color(0.8, 0.6, 1.0), true)
		e_hp = maxf(e_hp - back, 1.0)
	if perfect:
		stats.perfect += 1
		if element == "storm":
			var sd := slash_damage * 2.5 * _element_mult()
			hud.float_text(str(int(round(sd))), enemy.get_clash_point() + Vector3(0, 0.5, 0), Items.ELEMENT_COLORS.storm, true)
			e_hp = maxf(e_hp - sd, 1.0)
	if e_break >= def.break_max:
		e_break = 0.0
		sfx.play("break", 0.0, 0.0)
		hud.banner("BREAK!", Color(1.0, 0.85, 0.3), 0.9)
		_open(def.break_time, "broken")
	else:
		hud.banner("PERFECT PARRY" if perfect else "PARRY", Color(1.0, 0.95, 0.75), 0.5)
		_open(def.stagger_time + (0.5 if perfect else 0.0) + (0.35 if Run.perk("b2") else 0.0), "parry")
	if perfect and Run.perk("g3"):
		hud.float_text("RIPOSTE %d" % int(slash_damage * 1.5), enemy.get_clash_point() + Vector3(0.4, 0.2, 0), Color(0.6, 0.9, 1.0), true)
		e_hp = maxf(e_hp - slash_damage * 1.5, 1.0)


func _slash_hit(v: Vector2, letter: String, anim_dir: int) -> void:
	var dmg := slash_damage * (1.0 + 0.04 * hit_combo)
	if open_reason == "broken":
		dmg *= 1.25
	slash_seq.append(letter)
	var bonus := ""
	for c in COMBOS:
		var seq: Array = c.seq
		if slash_seq.size() >= seq.size() and slash_seq.slice(-seq.size()) == seq:
			var mult := float(c.mult)
			if family == "longsword" and c.name == "FLURRY":
				mult *= 1.2
			elif family == "greatsword" and c.name == "CLEAVE":
				mult = 3.0
			dmg *= mult
			bonus = c.name
			slash_seq.clear()
			break
	dmg *= _element_mult()
	if element == "ember":
		burn = 3.0
	if bonus != "" and element == "frost":
		chill = 5.0
		hud.float_text("CHILLED", enemy.get_clash_point() + Vector3(0, 0.8, 0), Items.ELEMENT_COLORS.frost)
	if bonus != "" and Run.perk("b3"):
		p_hp = minf(p_hp + 5.0, player_max_hp)
	if bonus != "" and family == "twin":
		dmg *= 1.5
	hit_combo += 1
	stats.best_combo = maxi(stats.best_combo, hit_combo)
	_add_surge(3.0)
	p_state = PState.SWING
	p_timer = slash_lock
	player.play(&"slash", anim_dir, 0.1)
	var side := -1 if letter == "L" else 1
	enemy.play(&"hit", side, 0.12)
	enemy.flash(Color(1.0, 0.9, 0.7))
	sfx.play("hit", 0.0, 0.15)
	_burst(enemy.get_clash_point(), 8)
	hud.slash_streak(v, bonus != "")
	var pos := enemy.get_clash_point() + Vector3(randf_range(-0.4, 0.4), 0.3, 0)
	if bonus != "":
		_shake = maxf(_shake, 0.9)
		cam.fov = 50.0
		sfx.play("clang", -4.0, 0.2)
		hud.banner(bonus, Color(1.0, 0.75, 0.3), 0.6)
		hud.float_text(str(int(round(dmg))), pos, Color(1.0, 0.7, 0.2), true)
		_hitstop(0.09)
		_buzz(45)
	else:
		_shake = maxf(_shake, 0.35)
		hud.float_text(str(int(round(dmg))), pos, Color(1, 0.95, 0.8))
		_hitstop(0.045)
		_buzz(15)
	stats.sword_dmg += minf(dmg, e_hp)
	_damage_enemy(dmg)


func _damage_enemy(dmg: float) -> void:
	e_hp -= dmg
	if e_hp <= 0.0:
		e_hp = 0.0
		e_state = EState.FINISHER
		e_timer = 3.0
		tutorial_hint = ""
		enemy.play(&"broken")
		_slow(0.25, 3.2)
		cinematic = 1.0
		_cam_to(Vector3(1.9, 1.5, 1.6), enemy.get_clash_point(), 0.5)
	elif not enraged and e_hp <= def.max_hp * 0.5:
		enraged = true
		e_speed *= 1.15
		hud.banner("ENRAGED", Color(1.0, 0.3, 0.2), 1.0)
		hud.caption(Story.bark(def.display_name, "enrage"))


func input_dodge(dir: int) -> void:
	if result != "" or not started or paused or blocking or p_state == PState.DEAD:
		return
	if p_state != PState.READY:
		_buffer("dodge", Vector2.ZERO, dir)
		return
	if dodge_charges < 1.0:
		hud.float_text("WINDED", player.get_clash_point() + Vector3(0, 0.6, 0), Color(0.7, 0.8, 1.0))
		return
	dodge_charges -= 1.0
	p_state = PState.DODGE
	dodge_dir = dir
	dodge_elapsed = 0.0
	player.play(&"dodge", dir)
	sfx.play("whoosh", -12.0)
	if _tutorial_slowed:
		_restore_time()
	if _move_tw:
		_move_tw.kill()
	_move_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_move_tw.tween_property(player, "position:x", player_home.x + 1.0 * dir, 0.14)
	_move_tw.tween_property(self, "_cam_offset_x", 0.35 * dir, 0.14)
	_move_tw.chain().tween_interval(0.14)
	_move_tw.chain().tween_property(player, "position:x", player_home.x, 0.18)
	_move_tw.parallel().tween_property(self, "_cam_offset_x", 0.0, 0.18)


func input_block(down: bool) -> void:
	if down and e_state == EState.FINISHER and can_spare:
		spare()
		return
	_block_wanted = down
	if result != "" or not started or paused or p_state == PState.DEAD:
		return
	if down:
		_block_time = stats.time
	if p_state == PState.READY:
		blocking = down and shield > 0.0
		player.play(&"block" if blocking else &"idle")
	elif not down:
		blocking = false


func input_super() -> void:
	if not pvp.is_empty():
		return
	if e_state == EState.FINISHER and result == "":
		take_throne()
		return
	if result != "" or not started or paused or super_meter < 100.0 or p_state != PState.READY:
		return
	if e_state in [EState.INTRO, EState.FINISHER, EState.DEAD]:
		return
	super_meter = 0.0
	sfx.play("break", 2.0, 0.0)
	hud.banner("EMBER SURGE", Color(1.0, 0.6, 0.2), 1.0)
	_shake = 1.2
	cam.fov = 47.0
	_burst(enemy.get_clash_point(), 28)
	enemy.flash(Color(1.0, 0.6, 0.2))
	_slow(0.3, 0.35)
	_buzz(80)
	_open(def.break_time, "broken")
	_damage_enemy(22.0 + slash_damage * 2.0)


func input_ranged() -> void:
	if result != "" or not started or paused or blocking or p_state != PState.READY or shots <= 0:
		return
	if e_state in [EState.INTRO, EState.FINISHER, EState.DEAD]:
		return
	shots -= 1
	stats.shots += 1
	if ranged_id == "hunters_bow":
		Run.add_mat("arrow", -1)
	p_state = PState.SWING
	p_timer = 0.35
	player.play(&"slash", 3, 0.12)
	sfx.play("whoosh", -3.0, 0.2)
	hud.shot_streak()
	_burst(enemy.get_clash_point(), 12)
	enemy.flash(Color(1, 1, 0.8))
	if e_state == EState.WINDUP:
		if _tutorial_slowed:
			_restore_time()
		hud.banner("INTERRUPTED", Color(0.9, 0.95, 1.0), 0.6)
		sfx.play("hit")
		_open(0.9, "parry")
	else:
		var dmg := 7.0 * float(Items.info(ranged_id).power) * ranged_mult
		hud.float_text(str(int(round(dmg))), enemy.get_clash_point() + Vector3(0, 0.4, 0), Color(0.9, 0.95, 1.0), true)
		sfx.play("hit")
		_damage_enemy(dmg)


func input_spell() -> void:
	if result != "" or not started or paused or spell_id == "" or mana < 100.0 or p_state == PState.DEAD:
		return
	if e_state in [EState.INTRO, EState.FINISHER, EState.DEAD]:
		return
	mana = 0.0
	stats.casts += 1
	sfx.play("break", -2.0, 0.1)
	_shake = maxf(_shake, 0.8)
	cam.fov = 50.0
	match spell_id:
		"ember_bolt":
			hud.banner("EMBER BOLT", Items.ELEMENT_COLORS.ember, 0.8)
			enemy.flash(Items.ELEMENT_COLORS.ember)
			_burst(enemy.get_clash_point(), 28)
			burn = 6.0
			var dmg := 42.0 * spell_mult * (1.3 if def.weak == "ember" else (0.75 if def.resist == "ember" else 1.0))
			hud.float_text(str(int(round(dmg))), enemy.get_clash_point() + Vector3(0, 0.5, 0), Items.ELEMENT_COLORS.ember, true)
			_damage_enemy(dmg)
		"frost_bind":
			hud.banner("FROST BIND", Items.ELEMENT_COLORS.frost, 0.8)
			enemy.flash(Items.ELEMENT_COLORS.frost)
			chill = 9.0
			if _tutorial_slowed:
				_restore_time()
			_open(1.8, "parry")
		"ward":
			hud.banner("WARD", Color(0.6, 0.75, 1.0), 0.8)
			player.flash(Color(0.5, 0.65, 1.0))
			warded = true


func spare() -> void:
	if e_state != EState.FINISHER or not can_spare:
		return
	e_state = EState.DEAD
	_restore_time()
	spared = true
	player.play(&"idle")
	enemy.play(&"broken")
	sfx.play("finish", 0.0, 0.0)
	hud.caption("...Then it ends with me. Go down, child. Leave the door open.")
	Run.data.cinders += 3
	Run.captions.append("You lowered the sword. The pyre guttered and went dark. For the first time, no one of your blood was owed to it.")
	_bank_kill()
	_end("win")


func take_throne() -> void:
	if e_state != EState.FINISHER or def.display_name not in ["The Hollow Regent", "The Usurper King"]:
		return
	Run.data.flags["throne"] = true
	Run.data.cinders += 2
	Run.captions.append("You took the crown from his head and the fire leaned toward you. Someone of your blood will climb to end you, in time.")
	hud.caption("Long may you burn.")
	_finish()


func input_potion() -> void:
	if result != "" or not started or paused or p_state == PState.DEAD or not pvp.is_empty():
		return
	if int(Run.data.potions) <= 0 or p_hp >= player_max_hp:
		return
	Run.data.potions -= 1
	p_hp = minf(p_hp + player_max_hp * 0.45, player_max_hp)
	player.flash(Color(0.3, 1.0, 0.5))
	hud.banner("FLASK", Color(0.5, 1.0, 0.6), 0.5)
	sfx.play("tell", -4.0, 0.0)


func set_paused(p: bool) -> void:
	if result != "" or not started:
		return
	paused = p
	get_tree().paused = p


func _finish() -> void:
	if e_state == EState.DEAD:
		return
	e_state = EState.DEAD
	_restore_time()
	player.play(&"slash", 1, 0.12)
	enemy.play(&"death")
	enemy.flash(Color.WHITE)
	enemy.set_tell(Color.BLACK, 0.1)
	sfx.play("finish", 2.0, 0.0)
	sfx.play("hit")
	_shake = 1.6
	_buzz(120)
	_burst(enemy.get_clash_point(), 28)
	hud.slash_streak(Vector2(1, -0.3), true)
	hud.caption(Story.bark(def.display_name, "death"))
	_bank_kill()
	if not others.is_empty():
		var next: Dictionary = others.pop_front()
		get_tree().create_timer(0.9).timeout.connect(func():
			if result == "":
				cinematic = 0.0
				_cam_to(CAM_POS, CAM_LOOK, 0.5)
				_face(next, 0.5)
				hud.banner(def.display_name, Color(1.0, 0.8, 0.5), 0.9))
		return
	get_tree().create_timer(0.5).timeout.connect(func(): player.play(&"victory"))
	_end("win")


func _bank_kill() -> void:
	slain.append({"node": enemy, "def": def, "enc": _enc})
	var bonus: int = int(stats.best_combo) * 2 if others.is_empty() else 0
	if stats.hits_taken == 0 and others.is_empty():
		bonus += 10
	Run.encounter = _enc
	var r := Run.on_win(bonus)
	reward.gold = int(reward.get("gold", 0)) + int(r.gold)
	reward.drops = (reward.get("drops", []) as Array) + (r.get("drops", []) as Array)
	reward.cleared = reward.get("cleared", false) or r.get("cleared", false)
	reward.kind = r.get("kind", "wild")
	reward.vit = float(reward.get("vit", 0.0)) + def.max_hp * 0.08


func _end(outcome: String) -> void:
	result = "pending"
	was_in_tower = Run.data.in_tower
	if outcome == "win":
		reward.flawless = stats.hits_taken == 0 and pvp.is_empty()
		reward.spared = spared
	elif pvp.is_empty():
		Run.on_lose()

	var gains := {
		"blade": int(stats.sword_dmg * 0.6),
		"guard": int(stats.parries) * 14 + int(stats.perfect) * 10 + int(stats.blocks) * 7 + int(stats.dodges) * 5,
		"archery": int(stats.shots) * 18,
		"sorcery": int(stats.casts) * 40,
		"vitality": int(stats.dmg_taken * 0.8 + float(reward.get("vit", 0.0))),
	}
	reward.gains = []
	for sk in gains:
		if gains[sk] > 0:
			var up := Run.train(sk, gains[sk])
			reward.gains.append([Craft.SKILLS[sk].name, gains[sk], Run.skill(sk), up])
	Run.gain_mastery(int(stats.sword_dmg))
	Run.xp_log.clear()
	Run.save()
	var wait := get_tree().create_timer(1.6, true, false, true)
	wait.timeout.connect(func():
		Engine.time_scale = _base_time
		_time_token += 1
		result = outcome
		hud.show_result(outcome == "win")
		if _bot != "":
			print("RESULT %s %s time=%.1f parries=%d perfect=%d dodges=%d best_combo=%d hits_taken=%d hp=%.0f gold=%d foes=%d" % [
				outcome, def.display_name, stats.time, stats.parries,
				stats.perfect, stats.dodges, stats.best_combo, stats.hits_taken, p_hp, int(reward.get("gold", 0)), slain.size()])
			if _bot == "tour" or host != null:
				proceed("")
			else:
				get_tree().quit())


func proceed(_unused: String) -> void:
	Engine.time_scale = 1.0 if _bot == "" else _base_time
	get_tree().paused = false
	if host == null:
		get_tree().change_scene_to_file(Run.home_scene())
		return
	if not pvp.is_empty() and Online.message.is_connected(_pvp_message):
		Online.message.disconnect(_pvp_message)
	_release()
	host.duel_done(result == "win", self)
	queue_free()


func _burst(pos: Vector3, amount: int) -> void:
	sparks.global_position = pos
	sparks.initial_velocity_max = 3.0 + amount * 0.14
	sparks.restart()
	sparks.emitting = true


func _buzz(ms: int) -> void:
	Input.vibrate_handheld(ms)


func _restore_time() -> void:
	_time_token += 1
	_tutorial_slowed = false
	Engine.time_scale = _base_time


func _slow(scale_f: float, real_seconds: float) -> void:
	_time_token += 1
	var token := _time_token
	Engine.time_scale = _base_time * scale_f
	get_tree().create_timer(real_seconds, true, false, true).timeout.connect(func():
		if token == _time_token:
			Engine.time_scale = _base_time)


func _hitstop(real_seconds: float) -> void:
	if Engine.time_scale < _base_time * 0.9:
		return
	_slow(0.05, real_seconds)


func _tick_bot() -> void:
	if _bot == "idle" or not pvp.is_empty():
		return
	if p_hp < player_max_hp * 0.4:
		input_potion()
	if mana >= 100.0:
		input_spell()
	if shots > 0 and e_state == EState.WINDUP and cur_attack.dir == AttackDef.Dir.THRUST and e_timer < 0.4:
		input_ranged()
	if _bot == "block":
		if not blocking:
			input_block(true)
		return
	if super_meter >= 100.0:
		input_super()
	for o in others:
		if float(o.tell) > 0.0 and float(o.tell) < 0.12 and p_state == PState.READY:
			input_dodge(1)
			return
	match e_state:
		EState.WINDUP:
			var d := cur_attack.dir
			if _bot == "dodge" or d == AttackDef.Dir.THRUST:
				if e_timer <= 0.12 and _feint_hold <= 0.0:
					input_dodge(1 if d == AttackDef.Dir.LEFT else -1)
			elif e_timer <= parry_window * 0.6 and _feint_hold <= 0.0 and p_state == PState.READY:
				input_swipe([Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1)][d])
		EState.OPEN, EState.FINISHER:
			if p_state == PState.READY:
				input_swipe(Vector2([-1, 1][hit_combo % 2], 0.2))
