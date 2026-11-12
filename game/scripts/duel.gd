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

const Tune := preload("res://scripts/combat_tune.gd")
const DuelFx := preload("res://scripts/duel_fx.gd")
const DuelPosture := preload("res://scripts/duel_posture.gd")
const DuelEnemy := preload("res://scripts/duel_enemy.gd")
const DuelStage := preload("res://scripts/duel_stage.gd")
const DuelPvp := preload("res://scripts/duel_pvp.gd")
const DuelBot := preload("res://scripts/duel_bot.gd")

var fx: DuelFx
var posture: DuelPosture
var ai: DuelEnemy
var stage: DuelStage
var pvp_net: DuelPvp
var bots: DuelBot

var host: Node3D
var player: FighterVisual
var enemy: FighterVisual
var foes: Array = []
var others: Array = []
var slain: Array = []

var pvp := {}
var pvp_turn := ""
var pvp_left := 0
var pvp_exec_until := 0
var _enc := {}

var def: EnemyDef
var hud: Hud
var sfx: Sfx
var cam: Camera3D
var sparks: CPUParticles3D
var sparks2: CPUParticles3D

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
var e_posture := 0.0
var e_speed := 1.0
var enraged := false
var open_reason := ""
var combo: Array = []
var combo_i := 0
var cur_attack: AttackDef
var windup_total := 1.0
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
	"sword_dmg": 0.0, "blocks": 0, "shots": 0, "casts": 0, "dmg_taken": 0.0, "execs": 0}
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
var _hold_for: PackedStringArray = []
var _hold_until := 0
var _shot_path := ""
var _shot_when := "windup"
var _buf := {"kind": "", "v": Vector2.ZERO, "dir": 0, "ms": 0}
var _t := 0.0
var _met_before := false


func _ready() -> void:
	fx = DuelFx.new(self)
	posture = DuelPosture.new(self)
	ai = DuelEnemy.new(self)
	stage = DuelStage.new(self)
	pvp_net = DuelPvp.new(self)
	bots = DuelBot.new(self)
	for part in [fx, posture, ai, stage, pvp_net, bots]:
		add_child(part)
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
		elif a.begins_with("--hold="):
			_hold_for = a.trim_prefix("--hold=").split(",")
		elif a.begins_with("--golden="):
			bots.golden_begin(a.trim_prefix("--golden="))
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
			Online.message.connect(pvp_net._pvp_message)
			if _bot != "":
				_base_time = 1.0
				Engine.time_scale = 1.0
		stage._place_in_world()
	_enc = foes[0].enc
	Run.encounter = _enc
	for i in range(1, foes.size()):
		var o: Dictionary = foes[i]
		o.merge({"hp": o.def.max_hp, "pst": 0.0, "enr": false, "spd": o.def.speed, "side": -1.0 if i % 2 == 1 else 1.0,
			"timer": 4.0 + i * 2.5, "tell": 0.0})
		others.append(o)
		stage._seat(o)
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
	sparks = fx._make_sparks()
	add_child(sparks)
	sparks2 = fx._make_sparks(Color(1.0, 0.95, 0.75), 0.07, 28)
	add_child(sparks2)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.duel = self
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	enemy.play(&"idle")
	player.play(&"idle")
	begin()


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
	if posture.classic():
		hud.caption("Classic duel: their game is older.")
	fx._cam_to(CAM_POS, CAM_LOOK, 1.6)
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(self, "cinematic", 0.0, 0.5)


func _process(delta: float) -> void:
	_t += delta
	fx._update_camera(delta)
	bots._take_shot_if_due()
	bots._hold_check()
	if not started or result != "":
		return
	if Time.get_ticks_msec() < _hold_until:
		return
	stats.time += delta
	_tick_player(delta)
	posture.tick(delta)
	ai._tick_enemy(delta)
	ai._tick_others(delta)
	if _bot != "":
		bots._tick_bot()


func _tick_player(delta: float) -> void:
	if spell_id != "":
		mana = minf(mana + delta * mana_rate, 100.0)
	if p_state != PState.DODGE:
		dodge_charges = minf(dodge_charges + delta * dodge_regen, dodge_max)
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
	if posture.p_stunned:
		posture.stun_end()
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


func switch_target(i: int) -> void:
	stage.switch_target(i)


func tell_color() -> Color:
	if cur_attack.dir == AttackDef.Dir.THRUST:
		return Color(1.0, 0.15, 0.1)
	if cur_attack.heavy:
		return Color(0.75, 0.3, 1.0)
	return Color(1.0, 0.6, 0.15)


func _hurt(dmg: float, dir: int) -> void:
	if warded:
		warded = false
		hud.banner("WARDED", Color(0.6, 0.75, 1.0), 0.6)
		sfx.play("clang", -4.0)
		fx._burst(player.get_clash_point() + Vector3(0, 0, -0.5), 20)
		return
	p_hp -= dmg
	hit_combo = 0
	stats.hits_taken += 1
	stats.dmg_taken += dmg
	_add_surge(6.0)
	if dmg >= player_max_hp * float(Tune.B1.hurt_big_frac):
		_shake = float(Tune.B1.hurt_big_shake)
		sfx.layer("L5")
	else:
		_shake = float(Tune.B1.hurt_shake)
		sfx.play("hurt")
	hud.hurt_flash()
	hud.enemy_streak(dir)
	player.flash(Color(1, 0.2, 0.15))
	player.play(&"hit", [-1, 1].pick_random(), 0.15)
	fx._hitstop(0.07)
	fx._buzz(60)
	posture.p_gain(float(Tune.B1.p_gain_hit) * dmg)
	if p_hp <= 0.0 and tutorial:
		p_hp = 1.0
	if p_hp <= 0.0:
		p_hp = 0.0
		p_state = PState.DEAD
		blocking = false
		player.play(&"death")
		enemy.play(&"victory")
		fx._slow(0.3, 1.0)
		if not pvp.is_empty():
			var stake := mini(int(int(Run.data.gold) * 0.1), 200) if pvp.zone else 0
			Run.data.gold -= stake
			Run.data.pvp_l += 1
			reward.lost_gold = stake
			Online.send_to(pvp.id, {"k": "dead", "gold": stake})
		_end("lose")
	else:
		p_timer = maxf(p_timer, 0.36) if p_state == PState.HIT and posture.p_stunned else 0.36
		p_state = PState.HIT
		posture.p_check_break()


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
		pvp_net._pvp_attack(swipe_letter(v))
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
			if open_reason == "posture":
				posture.execute(v, letter, anim_dir)
			else:
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
			fx._burst(enemy.get_clash_point(), 6)
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
		fx._restore_time()
	if not tutorial:
		posture.p_gain(float(Tune.B1.p_gain_whiff))
		posture.p_check_break()


func _parry(side: int) -> void:
	var perfect := e_timer <= PERFECT_PARRY and not _tutorial_slowed
	stats.parries += 1
	p_state = PState.SWING
	p_timer = 0.1
	player.play(&"parry", side)
	var mid := player.get_clash_point().lerp(enemy.get_clash_point(), 0.6)
	fx.parried(perfect, mid)
	if not pvp.is_empty():
		hud.banner("PERFECT PARRY" if perfect else "PARRY", Color(1.0, 0.95, 0.75), 0.5)
		e_state = EState.IDLE
		enemy.set_tell(Color.BLACK, 0.1)
		enemy.play(&"stagger")
		player.play(&"slash", -side, 0.12)
		pvp_net._pvp_report("parried", slash_damage * 2.0, perfect)
		pvp_net._pvp_my_turn()
		return
	_add_surge(15.0)
	mana = minf(mana + 10.0, 100.0)
	if leech > 0.0:
		p_hp = minf(p_hp + leech, player_max_hp)
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
	var gain := def.break_per_parry * float(Tune.B1.gain_perfect if perfect else Tune.B1.gain_parry)
	if not posture.e_gain(gain):
		hud.banner("PERFECT PARRY" if perfect else "PARRY", Color(1.0, 0.95, 0.75), 0.5)
		ai._open(def.stagger_time + (0.5 if perfect else 0.0) + (0.35 if Run.perk("b2") else 0.0), "parry")
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
	fx.cut_landed(v, letter, bonus != "")
	var pos := enemy.get_clash_point() + Vector3(randf_range(-0.4, 0.4), 0.3, 0)
	if bonus != "":
		hud.banner(bonus, Color(1.0, 0.75, 0.3), 0.6)
		hud.float_text(str(int(round(dmg))), pos, Color(1.0, 0.7, 0.2), true)
	else:
		hud.float_text(str(int(round(dmg))), pos, Color(1, 0.95, 0.8))
	stats.sword_dmg += minf(dmg, e_hp)
	_damage_enemy(dmg)
	posture.e_gain(float(Tune.B1.gain_ender if bonus != "" else Tune.B1.gain_cut))


## `by_execution`: the caller finishes the foe at once, so no killing-blow shot.
func _damage_enemy(dmg: float, by_execution := false) -> void:
	e_hp -= dmg
	if e_hp <= 0.0:
		e_hp = 0.0
		e_state = EState.FINISHER
		e_timer = 3.0
		tutorial_hint = ""
		enemy.play(&"broken")
		if not by_execution:
			fx.killing_blow()
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
		fx._restore_time()
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
	fx._burst(enemy.get_clash_point(), 28)
	enemy.flash(Color(1.0, 0.6, 0.2))
	fx._slow(0.3, 0.35)
	fx._buzz(80)
	ai._open(def.break_time, "broken")
	_damage_enemy(22.0 + slash_damage * 2.0)
	posture.e_gain(float(Tune.B1.gain_surge))


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
	fx._burst(enemy.get_clash_point(), 12)
	enemy.flash(Color(1, 1, 0.8))
	if e_state == EState.WINDUP:
		if _tutorial_slowed:
			fx._restore_time()
		hud.banner("INTERRUPTED", Color(0.9, 0.95, 1.0), 0.6)
		sfx.play("hit")
		ai._open(0.9, "parry")
		posture.e_gain(float(Tune.B1.gain_ranged))
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
			fx._burst(enemy.get_clash_point(), 28)
			burn = 6.0
			var dmg := 42.0 * spell_mult * (1.3 if def.weak == "ember" else (0.75 if def.resist == "ember" else 1.0))
			hud.float_text(str(int(round(dmg))), enemy.get_clash_point() + Vector3(0, 0.5, 0), Items.ELEMENT_COLORS.ember, true)
			_damage_enemy(dmg)
		"frost_bind":
			hud.banner("FROST BIND", Items.ELEMENT_COLORS.frost, 0.8)
			enemy.flash(Items.ELEMENT_COLORS.frost)
			chill = 9.0
			if _tutorial_slowed:
				fx._restore_time()
			ai._open(1.8, "parry")
			posture.e_gain(float(Tune.B1.gain_frost))
		"ward":
			hud.banner("WARD", Color(0.6, 0.75, 1.0), 0.8)
			player.flash(Color(0.5, 0.65, 1.0))
			warded = true


func spare() -> void:
	if e_state != EState.FINISHER or not can_spare:
		return
	e_state = EState.DEAD
	fx._restore_time()
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
	fx._restore_time()
	player.play(&"slash", 1, 0.12)
	enemy.play(&"death")
	enemy.flash(Color.WHITE)
	enemy.set_tell(Color.BLACK, 0.1)
	sfx.layer("L7")
	_shake = 1.6
	fx._buzz(120)
	fx._burst(enemy.get_clash_point(), 28)
	fx._burst2(enemy.get_clash_point(), 28)
	hud.slash_streak(Vector2(1, -0.3), true)
	hud.caption(Story.bark(def.display_name, "death"))
	_bank_kill()
	fx.deciding_blow()
	# The push-in, freeze and slow motion take about 1.1 s of real time; then the camera eases back.
	var shot := float(Tune.B1.push_time) + float(Tune.B1.push_freeze) + float(Tune.B1.push_slow_time) + 0.05
	if not others.is_empty():
		var next: Dictionary = others.pop_front()
		get_tree().create_timer(shot, true, false, true).timeout.connect(func():
			if result == "":
				cinematic = 0.0
				stage._face(next, 0.5)
				hud.banner(def.display_name, Color(1.0, 0.8, 0.5), 0.9))
		return
	get_tree().create_timer(shot, true, false, true).timeout.connect(func():
		if result == "pending":
			fx._cam_release()
			player.play(&"victory"))
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
		fx._restore_time()
		result = outcome
		hud.show_result(outcome == "win")
		if _bot != "":
			print("RESULT %s %s time=%.1f parries=%d perfect=%d dodges=%d best_combo=%d hits_taken=%d hp=%.0f gold=%d execs=%d foes=%d" % [
				outcome, def.display_name, stats.time, stats.parries,
				stats.perfect, stats.dodges, stats.best_combo, stats.hits_taken, p_hp, int(reward.get("gold", 0)), stats.execs, slain.size()])
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
	if not pvp.is_empty() and Online.message.is_connected(pvp_net._pvp_message):
		Online.message.disconnect(pvp_net._pvp_message)
	stage._release()
	host.duel_done(result == "win", self)
	queue_free()

